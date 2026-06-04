<template>
  <Dialog :key="track.TrackId" v-model:open="open" class="max-w-2xl">
    <DialogTrigger as-child>
      <Button variant="ghost">
        {{ translate('setup_race') }}
      </Button>
    </DialogTrigger>
    <DialogContent class="dark max-w-2xl max-h-[90vh] flex flex-col">
      <DialogHeader>
        <DialogTitle>
          {{ translate('selected_track') }} {{ track.RaceName }}
        </DialogTitle>
      </DialogHeader>
      <DialogDescription class="flex-1 min-h-0 overflow-y-auto pr-1">
        <form :id="'setup-'+track.TrackId">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
            <!-- Laps -->
            <FormField v-slot="{ componentField }" name="laps">
              <FormItem>
                <FormLabel>{{ translate('laps') }}</FormLabel>
                <FormControl>
                  <Select  v-bind="componentField" >
                    <SelectTrigger class="w-full">
                      <SelectValue :placeholder="translate('laps')" />
                    </SelectTrigger>
                    <SelectContent class="dark">
                      <SelectItem v-for="lap in lapsFiltered" :key="lap.value" :value="lap.value || 'sprint'">
                        {{ lap.text }}
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Buy In -->
            <FormField v-slot="{ componentField }" name="buyIn">
              <FormItem>
                <FormLabel>{{ translate('buy_in') }}</FormLabel>
                <FormControl>
                  <Select v-bind="componentField" class="input">
                    <SelectTrigger  class="w-full">
                      <SelectValue :placeholder="translate('buy_in')" />
                    </SelectTrigger>
                    <SelectContent class="dark" >
                      <SelectItem v-for="buyIn in globalStore.baseData.data.buyIns" :key="buyIn.value" :value="buyIn.value">
                        {{ buyIn.value }}
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Ghosting -->
            <FormField v-if="globalStore.baseData.data.ghostingEnabled" v-slot="{ componentField }" name="ghosting">
              <FormItem>
                <FormLabel>{{ translate('ghosting') }}</FormLabel>
                <FormControl>
                  <Select v-bind="componentField" class="input">
                    <SelectTrigger  class="w-full">
                      <SelectValue :placeholder="translate('ghosting')" />
                    </SelectTrigger>
                    <SelectContent class="dark" >
                      <SelectItem v-for="ghost in globalStore.baseData.data.ghostingTimes" :key="ghost.value" :value="ghost.value">
                        {{ ghost.text || ghost.value }}
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Max Class -->
            <FormField v-slot="{ componentField }" name="maxClass">
              <FormItem>
                <FormLabel>{{ translate('max_class') }}</FormLabel>
                <FormControl>
                  <Select v-bind="componentField" class="input">
                    <SelectTrigger  class="w-full">
                      <SelectValue :placeholder="translate('max_class')" />
                    </SelectTrigger>
                    <SelectContent class="dark" >
                      <SelectItem v-for="cls in globalStore.baseData.data.classes" :key="cls.value" :value="cls.value || 'NONE'">
                        {{ cls.text }}
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
            <!-- Host Drift -->
            <FormField v-if="globalStore.baseData.data.driftingIsEnabled && form.values.laps != -1 && !track.Metadata?.noDrift" type="checkbox" v-slot="{ componentField }" name="drift">
              <FormItem>
                <FormLabel>{{ translate('host_drift') }}</FormLabel>
                <FormControl>
                  <Switch v-bind="componentField" />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Host Silent -->
            <FormField  type="checkbox" v-slot="{ componentField }" name="silent">
              <FormItem>
                <FormLabel>{{ translate('host_silent') }}</FormLabel>
                <FormControl>
                  <Switch v-bind="componentField" />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Reversed -->
            <FormField  type="checkbox" v-if="globalStore.baseData.data.auth.startReversed" v-slot="{ componentField }" name="reversed">
              <FormItem>
                <FormLabel>{{ translate('reversed') }}</FormLabel>
                <FormControl>
                  <Switch v-bind="componentField" />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- First Person -->
            <FormField  type="checkbox" v-slot="{ componentField }" name="firstPerson">
              <FormItem>
                <FormLabel>{{ translate('first_person') }}</FormLabel>
                <FormControl>
                  <Switch v-bind="componentField" />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Random Vehicle Swapping -->
            <FormField
              v-if="globalStore?.baseData?.data?.auth?.adminMenu"
              type="checkbox"
              v-slot="{ componentField }"
              name="randomVehicleSwapping"
            >
              <FormItem>
                <FormLabel>{{ translate('random_vehicle_swapping') }}</FormLabel>
                <FormControl>
                  <Switch v-bind="componentField" />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
          </div>
          <div
            v-if="globalStore?.baseData?.data?.auth?.adminMenu && form.values.randomVehicleSwapping"
            class="mb-4 rounded-lg border border-border/60 bg-muted/20 p-4"
          >
            <div class="mb-3">
              <div class="text-sm font-medium">
                {{ translate('random_vehicle_categories') }}
              </div>
              <div class="text-xs text-muted-foreground">
                {{ translate('random_vehicle_categories_hint') }}
              </div>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div
                v-for="category in randomVehicleCategoryOptions"
                :key="category.value"
                class="flex items-center justify-between rounded-md border border-border/60 bg-background/60 px-3 py-2"
              >
                <span class="text-sm">{{ category.text }}</span>
                <Switch
                  :model-value="isRandomVehicleCategoryEnabled(category.value)"
                  @update:model-value="(value) => toggleRandomVehicleCategory(category.value, Boolean(value))"
                />
              </div>
            </div>
            <div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-3">
              <div class="flex items-center justify-between rounded-md border border-border/60 bg-background/60 px-3 py-2">
                <div class="pr-3">
                  <div class="text-sm">{{ translate('random_no_same_vehicle') }}</div>
                  <div class="text-xs text-muted-foreground">{{ translate('random_no_same_vehicle_hint') }}</div>
                </div>
                <Switch
                  :model-value="form.values.noSameRandomVehicle"
                  @update:model-value="(value) => form.setFieldValue('noSameRandomVehicle', Boolean(value))"
                />
              </div>
              <div class="flex items-center justify-between rounded-md border border-border/60 bg-background/60 px-3 py-2">
                <div class="pr-3">
                  <div class="text-sm">{{ translate('random_no_same_category') }}</div>
                  <div class="text-xs text-muted-foreground">{{ translate('random_no_same_category_hint') }}</div>
                </div>
                <Switch
                  :model-value="form.values.noSameRandomCategory"
                  @update:model-value="(value) => form.setFieldValue('noSameRandomCategory', Boolean(value))"
                />
              </div>
              <div class="flex items-center justify-between rounded-md border border-border/60 bg-background/60 px-3 py-2">
                <div class="pr-3">
                  <div class="text-sm">{{ translate('random_unique_category') }}</div>
                  <div class="text-xs text-muted-foreground">{{ translate('random_unique_category_hint') }}</div>
                </div>
                <Switch
                  :model-value="form.values.uniqueRandomCategory"
                  @update:model-value="(value) => form.setFieldValue('uniqueRandomCategory', Boolean(value))"
                />
              </div>
              <div class="flex items-center justify-between rounded-md border border-border/60 bg-background/60 px-3 py-2">
                <div class="pr-3">
                  <div class="text-sm">{{ translate('random_shared_categories') }}</div>
                  <div class="text-xs text-muted-foreground">{{ translate('random_shared_categories_hint') }}</div>
                </div>
                <Switch
                  :model-value="form.values.sharedRandomCategories"
                  @update:model-value="(value) => form.setFieldValue('sharedRandomCategories', Boolean(value))"
                />
              </div>
            </div>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
            <!-- Participation Money -->
            <FormField
              v-if="globalStore?.baseData?.data?.auth?.setupParticipation"
              v-slot="{ componentField }"
              name="participationMoney"
            >
              <FormItem>
                <FormLabel>{{ translate('participation_amount') }}</FormLabel>
                <FormControl>
                  <Input
                    type="number"
                    v-bind="componentField"
                    prepend-icon="mdi-help-circle-outline"
                    :prepend-tooltip="translate('participation_info')"
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Participation Currency -->
            <FormField
              v-if="globalStore?.baseData?.data?.auth?.setupParticipation"
              v-slot="{ componentField }"
              name="participationCurrency"
            >
              <FormItem>
                <FormLabel>{{ translate('currency') }}</FormLabel>
                <FormControl>
                  <Select v-bind="componentField" class="input">
                    <SelectTrigger  class="w-full">
                      <SelectValue :placeholder="translate('currency')" />
                    </SelectTrigger>
                    <SelectContent class="dark" >
                      <SelectItem v-for="cur in globalStore.baseData.data.participationCurrencyOptions" :key="cur.value" :value="cur.value">
                        {{ cur.text || cur.value }}
                      </SelectItem>
                    </SelectContent>
                  </Select>
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
            <!-- Ranked -->
            <FormField
              type="checkbox"
              v-if="globalStore?.baseData?.data?.auth?.startRanked"
              v-slot="{ componentField }"
              name="ranked"
            >
              <FormItem>
                <FormLabel>{{ translate('ranked') }}</FormLabel>
                <FormControl>
                  <Switch :disabled="setupData.laps === -1" v-bind="componentField" />
                </FormControl>
                <FormMessage />
              </FormItem>
            </FormField>
          </div>
        </form>
      </DialogDescription>
      <DialogFooter class="shrink-0">
        <Button :disabled="globalStore.activeRace?.raceName" type="button" @click="handleConfirm">
          {{ translate('confirm') }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>

<script setup lang="ts">
import { ref, computed } from "vue";
import api from "@/api/axios";
import { closeApp } from "@/helpers/closeApp";
import { useGlobalStore } from "@/store/global";
import { Track } from "@/store/types";
import { translate } from "@/helpers/translate";
import { toast } from "vue-sonner";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import Switch from "@/components/ui/switch/Switch.vue";
import Input from "@/components/ui/input/Input.vue";
import {
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useForm } from "vee-validate";

const props = defineProps<{
  track: Track;
}>();

const emits = defineEmits(["goBack"]);
const globalStore = useGlobalStore();
const open = ref(false);

const lapsFiltered = computed(() =>
  globalStore.baseData.data.laps.filter((lapType) => {
    if (lapType.value === -1) {
      // For elimination
      return globalStore.baseData.data.auth.startElimination;
    }
    if (props.track.Metadata?.raceType) {
      if (props.track.Metadata.raceType === 'sprint' && lapType.value > 0) return false
      if (props.track.Metadata.raceType === 'circuit_only' && lapType.value === 0) return false
    }
    return true;
  })
);

const trackHasDefinedType = props.track.Metadata?.raceType === 'circuit_only' || props.track.Metadata?.raceType === 'sprint'
const defaultLapValue = trackHasDefinedType ? (
  props.track.Metadata?.raceType === 'circuit_only' ? globalStore.baseData.data.laps[2].value :'sprint' ):
  'sprint'
const randomVehicleCategoryOptions = computed(() => globalStore.baseData.data.randomVehicleCategoryOptions ?? []);
const defaultRandomVehicleCategories = randomVehicleCategoryOptions.value.map((option) => option.value);

const setupData = ref({
  laps: defaultLapValue,
  buyIn: globalStore.baseData.data.buyIns[0].value,
  ghosting: globalStore.baseData.data.ghostingTimes[0].value,
  maxClass: globalStore.baseData.data.classes[0].value == '' ? 'NONE' : globalStore.baseData.data.classes[0].value,
  ranked: false,
  reversed: false,
  firstPerson: false,
  participationMoney: 0,
  participationCurrency: globalStore.baseData.data.participationCurrencyOptions[0].value,
  silent: false,
  drift: false,
  randomVehicleSwapping: false,
  randomVehicleCategories: defaultRandomVehicleCategories,
  noSameRandomVehicle: false,
  noSameRandomCategory: false,
  uniqueRandomCategory: false,
  sharedRandomCategories: false,
  trackId: props.track.TrackId,
});

const form = useForm({
  initialValues: setupData.value,
})

const isRandomVehicleCategoryEnabled = (category: string) =>
  (form.values.randomVehicleCategories ?? []).includes(category);

const toggleRandomVehicleCategory = (category: string, enabled: boolean) => {
  const categories = new Set(form.values.randomVehicleCategories ?? []);

  if (enabled) {
    categories.add(category);
  } else {
    categories.delete(category);
  }

  form.setFieldValue("randomVehicleCategories", Array.from(categories));
};

const handleConfirm = async () => {
  if (form.values.participationMoney < 0)
    form.values.participationMoney = 0;
  if (form.values.laps === -1) {
    form.values.ranked = false;
    form.values.drift = false
  }
  if (form.values.randomVehicleSwapping && (form.values.randomVehicleCategories?.length ?? 0) === 0) {
    toast.error(translate('random_vehicle_category_required'));
    return;
  }
  
  let maxClass;
  if (form.values.maxClass === 'NONE') {
    maxClass = '';
  } else {
    maxClass = form.values.maxClass
  }
  let laps;
  if (form.values.laps === 'sprint') {
    laps = 0;
  } else {
    laps = form.values.laps
  }

  let data = {
    trackId: props.track.TrackId,
    laps: laps,
    buyIn: form.values.buyIn,
    maxClass: maxClass,
    ghostingOn: form.values.ghosting !== -1,
    ghostingTime: form.values.ghosting,
    ranked: form.values.ranked,
    participationMoney: form.values.participationMoney,
    participationCurrency: form.values.participationCurrency,
    reversed: form.values.reversed,
    firstPerson: form.values.firstPerson,
    silent: form.values.silent,
    drift: form.values.drift,
    randomVehicleSwapping: form.values.randomVehicleSwapping,
    randomVehicleCategories: form.values.randomVehicleSwapping ? form.values.randomVehicleCategories : [],
    noSameRandomVehicle: form.values.randomVehicleSwapping ? form.values.noSameRandomVehicle : false,
    noSameRandomCategory: form.values.randomVehicleSwapping ? form.values.noSameRandomCategory : false,
    uniqueRandomCategory: form.values.randomVehicleSwapping ? form.values.uniqueRandomCategory : false,
    sharedRandomCategories: form.values.randomVehicleSwapping ? form.values.sharedRandomCategories : false,
  };

  const res = await api.post("UiSetupRace", JSON.stringify(data));
  if (res.data) {
    globalStore.$state.currentTab.racing = "current";
    closeApp();
    emits("goBack");
  }
};
</script>